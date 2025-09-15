# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Algorithm, type: :model do
  describe 'validations' do
    it 'requires a name' do
      algorithm = described_class.new(description: 'Test description')
      expect(algorithm).not_to be_valid
      expect(algorithm.errors[:name]).to include("can't be blank")
    end

    it 'requires a description' do
      algorithm = described_class.new(name: 'Test Algorithm')
      expect(algorithm).not_to be_valid
      expect(algorithm.errors[:description]).to include("can't be blank")
    end

    it 'is valid with name and description' do
      algorithm = described_class.new(
        name: 'Test Algorithm',
        description: 'A test trading strategy'
      )
      expect(algorithm).to be_valid
    end
  end

  describe 'database columns' do
    it 'has the expected columns' do
      expect(described_class.column_names).to include('name', 'description', 'created_at', 'updated_at')
    end
  end
end
