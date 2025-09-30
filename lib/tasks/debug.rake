# frozen_string_literal: true

namespace :debug do
  desc 'Diagnoses the QuiverClient configuration'
  task quiver_client: :environment do
    puts "--- Debugging QuiverClient ---"
    client = QuiverClient.new
    puts "API Key being used: #{client.instance_variable_get(:@connection).headers['Authorization']}"
    puts "--- End Debug ---"
  end
end
