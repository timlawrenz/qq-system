# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gem Setup', type: :feature do
  describe 'Packwerk' do
    it 'is properly configured' do
      expect(File.exist?('packwerk.yml')).to be true
      expect(File.exist?('package.yml')).to be true
    end
  end

  describe 'SolidQueue' do
    it 'configuration files exist' do
      expect(File.exist?('config/queue.yml')).to be true
      expect(File.exist?('config/recurring.yml')).to be true
      expect(File.exist?('db/queue_schema.rb')).to be true
      expect(File.exist?('bin/jobs')).to be true
    end
  end

  describe 'RSpec' do
    it 'is properly configured' do
      expect(File.exist?('spec/spec_helper.rb')).to be true
      expect(File.exist?('spec/rails_helper.rb')).to be true
      expect(File.exist?('.rspec')).to be true
    end

    it 'includes packs-rails rspec integration' do
      rspec_content = File.read('.rspec')
      expect(rspec_content).to include('--require packs/rails/rspec')
    end
  end
end
