require 'httparty'
require 'dotenv'
require 'base64'
require 'mini_magick'

Dotenv.load

class SpotifyClient
  SPOTIFY_API_URL = 'https://api.spotify.com/v1'
  MAX_IMAGE_FILE_SIZE = 256 * 1024
  MIN_IMAGE_QUALITY = 10

  def initialize
    @access_token = refresh_access_token
    @user_id = get_spotify_user_id
  end

  def get_top_artists(limit = 10, time_range = 'long_term')
    response = HTTParty.get("#{SPOTIFY_API_URL}/me/top/artists", query: { limit: limit, time_range: time_range }, headers: { "Authorization" => "Bearer #{@access_token}" })
    if response.success?
      response.parsed_response['items']
    else
      []
    end
  end

  def get_top_genres(limit = 50, time_range = 'long_term')
    top_artists = get_top_artists(50)
    genres = top_artists.map { |artist| artist['genres'] }.flatten
    genre_counts = genres.each_with_object(Hash.new(0)) { |genre, counts| counts[genre] += 1 }
    sorted_genres = genre_counts.select { |genre, count| count > 1 }.sort_by { |genre, count| -count }.map(&:first)
    sorted_genres.take(limit)
  end

  def create_playlist(playlist_name, playlist_description = '')
    options = {
      headers: { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "application/json" },
      body: { name: playlist_name, description: playlist_description, public: true }.to_json
    }
    response = HTTParty.post("#{SPOTIFY_API_URL}/users/#{@user_id}/playlists", options)
    response.parsed_response['id']
  end

  def modify_playlist(playlist_id, name, description)
    options = {
      headers: { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "application/json" },
      body: { name: name, description: description }.to_json
    }
    response = HTTParty.put("#{SPOTIFY_API_URL}/playlists/#{playlist_id}", options)
    response.success?
  end

  def search_playlists(search_string)
    options = {
      headers: { "Authorization" => "Bearer #{@access_token}" },
      query: { limit: 50, offset: 0 }
    }
    response = HTTParty.get("#{SPOTIFY_API_URL}/users/#{@user_id}/playlists", options)
    playlist_id = find_playlist_id(response.parsed_response['items'], search_string)
    return playlist_id unless playlist_id.nil?

    while response.parsed_response['next']
      next_url = response.parsed_response['next']
      response = HTTParty.get(next_url, headers: { "Authorization" => "Bearer #{@access_token}" })
      playlist_id = find_playlist_id(response.parsed_response['items'], search_string)
      return playlist_id unless playlist_id.nil?
    end

    nil
  end

  def find_playlist_id(playlists, search_string)
    playlist = playlists.find { |p| p['name'].downcase.include?(search_string.downcase) }
    playlist['id'] if playlist
  end

  def search_tracks(track_name, artist_name)
    return if track_name.nil? || artist_name.nil?
    query = "#{track_name} artist:#{artist_name}"
    response = HTTParty.get("#{SPOTIFY_API_URL}/search", query: { type: 'track', limit: 1, q: query }, headers: { "Authorization" => "Bearer #{@access_token}" })
    if response.parsed_response['tracks'] && response.parsed_response['tracks']['items'].any?
      artists = response.parsed_response['tracks']['items'].first['artists'].map { |artist| artist['name'] }.join(", ")
      puts "#{artists} – #{response.parsed_response['tracks']['items'].first['name']}"
      response.parsed_response['tracks']['items'].first['uri']
    else
      puts "Searched for: #{artist_name} – #{track_name}, found nothing."
      nil
    end
  end

  def replace_playlist_tracks(playlist_id, track_uris)
    options = {
      headers: { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "application/json" },
      body: { uris: track_uris }.to_json
    }
    HTTParty.put("#{SPOTIFY_API_URL}/playlists/#{playlist_id}/tracks", options)
  end

  def set_playlist_cover(playlist_id, png_data)
    jpg_data = png_to_jpg(png_data)

    options = {
      headers: { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "image/jpeg" },
      body: Base64.strict_encode64(jpg_data)
    }
    response = nil
    retries = 5
    backoff = 1
    while retries > 0
      response = HTTParty.put("#{SPOTIFY_API_URL}/playlists/#{playlist_id}/images", options)
      break if response.success?
      sleep backoff
      backoff *= 2
      retries -= 1
    end
    puts (response.success? ? "Playlist cover image saved." : "Sorry! I couldn't save the playlist cover image.")
  end

  private

  def refresh_access_token
    options = {
      body: { grant_type: 'refresh_token', refresh_token: ENV['SPOTIFY_REFRESH_TOKEN'] },
      headers: { "Authorization" => "Basic " + Base64.strict_encode64("#{ENV['SPOTIFY_CLIENT_ID']}:#{ENV['SPOTIFY_CLIENT_SECRET']}"), "Content-Type" => "application/x-www-form-urlencoded" }
    }
    response = HTTParty.post("https://accounts.spotify.com/api/token", options)
    response.parsed_response['access_token']
  end

  def get_spotify_user_id
    response = HTTParty.get("#{SPOTIFY_API_URL}/me", headers: { "Authorization" => "Bearer #{@access_token}" })
    response.parsed_response['id']
  end

  def png_to_jpg(png_data)
    png = Base64.decode64(png_data)
    image = MiniMagick::Image.read(png)
    image.format("jpeg")
    image.resize("640x640")
    quality = 80
    image.quality(quality)
    jpeg_data = image.to_blob

    # Reduce the quality until the file size is less than MAX_IMAGE_FILE_SIZE
    while jpeg_data.length > MAX_IMAGE_FILE_SIZE && quality > MIN_IMAGE_QUALITY
      quality -= 5
      image.quality(quality)
      jpeg_data = image.to_blob
    end

    jpeg_data
  end
end
