# frozen_string_literal: true

require 'gl_command/rspec'

RSpec.configure do |config|
  config.include GLCommand::Matchers, type: :command
  config.include_context 'GLCommand::Command subject', type: :command
end
