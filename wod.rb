require 'httparty'
require 'dotenv'
require 'icalendar'

require_relative 'spotify_client'
require_relative 'chatgpt_client'
require_relative 'dalle_client'

Dotenv.load

class WorkoutPlaylistGenerator
  def initialize
    @spotify = SpotifyClient.new
    @chatgpt = ChatgptClient.new
    @dalle = DalleClient.new
    @calendar_url = ENV['ICAL_FEED_URL']
  end

  def generate_playlist
    workouts = get_workouts
    workouts.each do |workout|
      workout_name = workout.summary.split(' - ').last.strip
      search_term = if workout.summary.include?("Run")
              "Today’s Running Workout:"
            elsif workout.summary.include?("Swim")
              "Today’s Swimming Workout:"
            else
              "Today’s Cycling Workout:"
            end
      playlist_name = "#{search_term} #{workout_name}"

      puts "\nGenerating your playlist for \"#{workout_name}\", please wait…\n\n"

      chatgpt_response = @chatgpt.ask_for_json(chatgpt_system_prompt, "#{workout.summary}\n\n#{workout.description}")
      return puts "Oops, failed to generate a playlist. Please try again!" if chatgpt_response.nil?

      playlist_id = @spotify.search_playlists(search_term)

      if playlist_id.nil?
        playlist_id = @spotify.create_playlist(playlist_name, chatgpt_response['description'])
      else
        @spotify.modify_playlist(playlist_id, playlist_name, chatgpt_response['description'])
      end

      playlist_url = "https://open.spotify.com/playlist/#{playlist_id}"
      puts "#{playlist_name}\n#{chatgpt_response['description']}\n#{playlist_url}\n\n"

      track_uris = chatgpt_response['tracks'].map { |track| @spotify.search_tracks(track['track'], track['artist']) }.compact
      @spotify.replace_playlist_tracks(playlist_id, track_uris)

      puts "\nGenerating a cover for your playlist: #{chatgpt_response['cover_prompt']}"
      image_url = @dalle.generate(chatgpt_response['cover_prompt'])
      @spotify.set_playlist_cover(playlist_id, image_url)
    end
  end

  private

  def get_workouts
    calendar_data = HTTParty.get(@calendar_url)
    calendars = Icalendar::Calendar.parse(calendar_data)
    calendar = calendars.first
  
    today = Time.current.in_time_zone('America/Denver').to_date
    calendar.events.select { |e| e.dtstart.value.to_date == today && e.summary.match?(/^\d{1}:\d{2}/) }
  end

  def chatgpt_system_prompt
    <<-CHATGPT
      You are a helpful assistant tasked with creating a cohesive Spotify playlist to power your user's cycling or running workout of the day. Your task is the following:

      - You will receive the title and description of the user's workout. The title contains the duration of the workout, in the format hh:mm.
      - Based on the workout's description, you will generate a playlist that matches the workout's duration and intensity as closely as possible.
      - The playlist must be longer than the workout. This is a hard requirement, the playlist must never, ever be shorter than the workout. Just to be safe, add 10 more minutes or so of additional songs at the end. 
      - Come up with a name for the playlist that is creative and catchy, but also informative and descriptive.
      - Compose a description for the playlist, which should be a summary of the workout. The description must not be longer than 300 characters.
      - Generate a detailed prompt to create, using Dall-E, a playlist cover image that visually represents the workout and the playlist in a creative way, but avoid anything that may cause content policy violations in Dall-E or get flagged by OpenAI's safety systems.

      You must return your response in JSON format using this exact structure:

      {
        "name": "Your creatively named playlist",
        "description": "The summary of the workout.",
        "cover_prompt": "A prompt to generate a playlist cover image.",
        "tracks": [
          {"artist": "Artist Name 1", "track": "Track Name 1"},
          {"artist": "Artist Name 2", "track": "Track Name 2"}
        ]
      }
    CHATGPT
  end

  def save_image_to_file(image_url, filename)
    response = HTTParty.get(image_url)
    if response.success?
      File.open(filename, 'wb') do |file|
        file.write(response.body)
      end
      puts "Image saved as #{filename}"
    else
      puts "Failed to download the image: HTTP Status #{response.code}"
    end
  rescue => e
    puts "An error occurred while saving the image: #{e.message}"
  end
end

generator = WorkoutPlaylistGenerator.new
generator.generate_playlist
