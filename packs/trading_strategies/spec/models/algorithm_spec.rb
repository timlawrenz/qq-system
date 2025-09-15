# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Algorithm do
  describe 'validations' do
    it 'requires a name' do
      algorithm = build(:algorithm, name: nil)
      expect(algorithm).not_to be_valid
      expect(algorithm.errors[:name]).to include("can't be blank")
    end

    it 'requires a description' do
      algorithm = build(:algorithm, description: nil)
      expect(algorithm).not_to be_valid
      expect(algorithm.errors[:description]).to include("can't be blank")
    end

    it 'is valid with name and description' do
      algorithm = build(:algorithm)
      expect(algorithm).to be_valid
    end
  end

  describe 'database columns' do
    it 'has the expected columns' do
      expect(described_class.column_names).to include('name', 'description', 'created_at', 'updated_at')
    end
  end

  describe 'factory' do
    it 'creates a valid algorithm' do
      algorithm = create(:algorithm)
      expect(algorithm).to be_persisted
      expect(algorithm.name).to be_present
      expect(algorithm.description).to be_present
    end
  end
end
