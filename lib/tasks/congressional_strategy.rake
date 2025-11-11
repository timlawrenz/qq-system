# frozen_string_literal: true

namespace :congressional_strategy do
  desc 'Seed committee and industry data'
  task seed_data: :environment do
    puts 'Seeding industries...'
    seed_industries

    puts "\nSeeding committees..."
    seed_committees

    puts "\nMapping committees to industries..."
    map_committees_to_industries

    puts "\n✓ Seed data complete!"
    puts "  Industries: #{Industry.count}"
    puts "  Committees: #{Committee.count}"
    puts "  Mappings: #{CommitteeIndustryMapping.count}"
  end

  def seed_industries
    industries_data = [
      { name: 'Technology', sector: 'Information Technology', description: 'Software, cloud computing, IT services' },
      { name: 'Semiconductors', sector: 'Information Technology',
        description: 'Chip manufacturing, semiconductor equipment' },
      { name: 'Healthcare', sector: 'Healthcare', description: 'Pharmaceuticals, biotech, medical devices' },
      { name: 'Energy', sector: 'Energy', description: 'Oil, gas, renewable energy, utilities' },
      { name: 'Financial Services', sector: 'Financials', description: 'Banks, insurance, investment firms' },
      { name: 'Defense', sector: 'Industrials', description: 'Defense contractors, aerospace' },
      { name: 'Aerospace', sector: 'Industrials', description: 'Aircraft manufacturing, space technology' },
      { name: 'Telecommunications', sector: 'Communication Services',
        description: 'Telecom providers, network infrastructure' },
      { name: 'Consumer Goods', sector: 'Consumer Discretionary', description: 'Retail, consumer products' },
      { name: 'Agriculture', sector: 'Consumer Staples', description: 'Farming, food production' },
      { name: 'Transportation', sector: 'Industrials', description: 'Airlines, railroads, shipping' },
      { name: 'Real Estate', sector: 'Real Estate', description: 'REITs, property development' },
      { name: 'Media & Entertainment', sector: 'Communication Services',
        description: 'Broadcasting, streaming, content' },
      { name: 'Automotive', sector: 'Consumer Discretionary', description: 'Auto manufacturers, EV companies' },
      { name: 'Other', sector: 'Other', description: 'Uncategorized industries' }
    ]

    industries_data.each do |data|
      Industry.find_or_create_by!(name: data[:name]) do |industry|
        industry.sector = data[:sector]
        industry.description = data[:description]
      end
    end
  end

  def seed_committees
    committees_data = [
      # House Committees
      { code: 'HSAG', name: 'Agriculture', chamber: 'house', description: 'Agriculture, nutrition, forestry' },
      { code: 'HSAP', name: 'Appropriations', chamber: 'house', description: 'Federal budget and spending' },
      { code: 'HSAS', name: 'Armed Services', chamber: 'house', description: 'National defense, military' },
      { code: 'HSBA', name: 'Financial Services', chamber: 'house', description: 'Banking, housing, insurance' },
      { code: 'HSBU', name: 'Budget', chamber: 'house', description: 'Federal budget process' },
      { code: 'HSED', name: 'Education and Labor', chamber: 'house', description: 'Education, workforce' },
      { code: 'HSIF', name: 'Energy and Commerce', chamber: 'house', description: 'Energy, health, tech, commerce' },
      { code: 'HSFA', name: 'Foreign Affairs', chamber: 'house', description: 'International relations' },
      { code: 'HSHM', name: 'Homeland Security', chamber: 'house', description: 'Domestic security' },
      { code: 'HSHA', name: 'House Administration', chamber: 'house', description: 'House operations' },
      { code: 'HSJU', name: 'Judiciary', chamber: 'house', description: 'Courts, law enforcement, immigration' },
      { code: 'HSNR', name: 'Natural Resources', chamber: 'house', description: 'Public lands, energy, environment' },
      { code: 'HSSY', name: 'Science, Space, and Technology', chamber: 'house',
        description: 'Science research, space' },
      { code: 'HSSM', name: 'Small Business', chamber: 'house', description: 'Small business issues' },
      { code: 'HSPW', name: 'Transportation and Infrastructure', chamber: 'house',
        description: 'Transportation, infrastructure' },
      { code: 'HSVR', name: "Veterans' Affairs", chamber: 'house', description: 'Veterans benefits and services' },
      { code: 'HSWM', name: 'Ways and Means', chamber: 'house', description: 'Taxation, trade, Social Security' },

      # Senate Committees
      { code: 'SSAF', name: 'Agriculture, Nutrition, and Forestry', chamber: 'senate',
        description: 'Agriculture, nutrition' },
      { code: 'SSAP', name: 'Appropriations', chamber: 'senate', description: 'Federal spending' },
      { code: 'SSAS', name: 'Armed Services', chamber: 'senate', description: 'National defense' },
      { code: 'SSBK', name: 'Banking, Housing, and Urban Affairs', chamber: 'senate', description: 'Banking, housing' },
      { code: 'SSBU', name: 'Budget', chamber: 'senate', description: 'Federal budget' },
      { code: 'SSCM', name: 'Commerce, Science, and Transportation', chamber: 'senate',
        description: 'Commerce, science, transportation' },
      { code: 'SSEG', name: 'Energy and Natural Resources', chamber: 'senate', description: 'Energy, public lands' },
      { code: 'SSEV', name: 'Environment and Public Works', chamber: 'senate',
        description: 'Environment, infrastructure' },
      { code: 'SSFR', name: 'Finance', chamber: 'senate', description: 'Taxation, trade, healthcare' },
      { code: 'SSFO', name: 'Foreign Relations', chamber: 'senate', description: 'Foreign policy' },
      { code: 'SSGA', name: 'Homeland Security and Governmental Affairs', chamber: 'senate',
        description: 'Homeland security, government operations' },
      { code: 'SSHR', name: 'Health, Education, Labor, and Pensions', chamber: 'senate',
        description: 'Health, education, labor' },
      { code: 'SSCN', name: 'Indian Affairs', chamber: 'senate', description: 'Native American issues' },
      { code: 'SSJU', name: 'Judiciary', chamber: 'senate', description: 'Courts, law, immigration' },
      { code: 'SSSB', name: 'Small Business and Entrepreneurship', chamber: 'senate', description: 'Small business' },
      { code: 'SSVA', name: "Veterans' Affairs", chamber: 'senate', description: 'Veterans services' }
    ]

    committees_data.each do |data|
      Committee.find_or_create_by!(code: data[:code]) do |committee|
        committee.name = data[:name]
        committee.chamber = data[:chamber]
        committee.description = data[:description]
      end
    end
  end

  def map_committees_to_industries
    mappings = {
      # House Energy and Commerce -> Tech, Healthcare, Energy, Telecom
      'HSIF' => %w[Technology Semiconductors Healthcare Energy Telecommunications],

      # House Armed Services -> Defense, Aerospace
      'HSAS' => %w[Defense Aerospace],

      # House Financial Services -> Financial Services
      'HSBA' => ['Financial Services'],

      # House Agriculture -> Agriculture
      'HSAG' => ['Agriculture'],

      # House Transportation -> Transportation, Aerospace
      'HSPW' => %w[Transportation Aerospace],

      # House Science, Space, and Technology -> Technology, Aerospace
      'HSSY' => %w[Technology Semiconductors Aerospace],

      # House Natural Resources -> Energy
      'HSNR' => ['Energy'],

      # Senate Armed Services -> Defense, Aerospace
      'SSAS' => %w[Defense Aerospace],

      # Senate Banking -> Financial Services
      'SSBK' => ['Financial Services'],

      # Senate Commerce -> Tech, Telecom, Transportation
      'SSCM' => %w[Technology Telecommunications Transportation Aerospace],

      # Senate Energy -> Energy
      'SSEG' => ['Energy'],

      # Senate Finance -> Financial Services, Healthcare
      'SSFR' => ['Financial Services', 'Healthcare'],

      # Senate HELP -> Healthcare
      'SSHR' => ['Healthcare'],

      # Senate Agriculture -> Agriculture
      'SSAF' => ['Agriculture']
    }

    mappings.each do |committee_code, industry_names|
      committee = Committee.find_by(code: committee_code)
      next unless committee

      industry_names.each do |industry_name|
        industry = Industry.find_by(name: industry_name)
        next unless industry

        CommitteeIndustryMapping.find_or_create_by!(
          committee: committee,
          industry: industry
        )
      end
    end
  end
end
