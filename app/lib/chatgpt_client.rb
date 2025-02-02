require 'httparty'
require 'json'

# Represents a client for interacting with the ChatGPT API.
class ChatgptClient
  OPENAI_API_URL = 'https://api.openai.com/v1'

  # Initializes a new instance of the ChatgptClient class.
  def initialize
    @api_key = ENV['OPENAI_API_KEY']
  end

  # Sends a request to the ChatGPT API and returns the response as a JSON object.
  #
  # @param system_prompt [String] The system prompt.
  # @param user_prompt [String] The user prompt.
  # @param user_id [Int] The ID of the user making the request
  # @return [Hash] The response as a JSON object.
  def ask_for_json(system_prompt, user_prompt, user_id)
    options = {
      headers: { "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}", "Content-Type" => "application/json" },
      body: {
        model: 'gpt-4o',
        response_format: { type: "json_object" },
        user: user_id.to_s,
        messages: [
          {
            role: 'system',
            content: system_prompt
          },
          {
            role: 'user',
            content: user_prompt
          }
        ]
      }.to_json
    }
    response = HTTParty.post("#{OPENAI_API_URL}/chat/completions", options)
    if response.success?
      JSON.parse(response.parsed_response['choices'].first['message']['content'])
    else
      raise "ChatGPT API request failed with status code #{response.code}: #{response.message}"
    end
  rescue JSON::ParserError
    {}
  end
end
