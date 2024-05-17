require 'httparty'
require 'dotenv'
require 'icalendar'
require 'json'

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
    @chatgpt_prompt = File.read('prompts/wod.txt')
  end

  def generate_playlist
    workouts = get_workouts
    workouts.each do |workout|
      workout_duration = extract_workout_duration(workout.summary)
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

      chatgpt_response = @chatgpt.ask_for_json(@chatgpt_prompt, "#{workout.summary}\n\n#{workout.description}")
      return puts "Oops, failed to generate a playlist. Please try again!" if chatgpt_response.nil?

      playlist_id = @spotify.search_playlists(search_term)

      if playlist_id.nil?
        playlist_id = @spotify.create_playlist(playlist_name, chatgpt_response['description'])
      else
        @spotify.modify_playlist(playlist_id, playlist_name, chatgpt_response['description'])
      end

      playlist_url = "https://open.spotify.com/playlist/#{playlist_id}"
      puts "#{playlist_name}\n#{chatgpt_response['description']}\n#{playlist_url}\n\n"

      total_duration = 0
      track_uris = []
      chatgpt_response['tracks'].each do |track|
        track_info = @spotify.search_tracks(track['track'], track['artist'])
        if track_info
          track_uris << track_info['uri']
          total_duration += track_info['duration_ms']
        end
        break if total_duration >= workout_duration
      end

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
    @chatgpt_prompt
  end

  def extract_workout_duration(summary)
    duration_str = summary.split(' - ').first.strip
    hours, minutes = duration_str.split(':').map(&:to_i)
    (hours * 60 + minutes) * 60 * 1000 # Convert to milliseconds
  end
end

generator = WorkoutPlaylistGenerator.new
generator.generate_playlist
