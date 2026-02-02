# frozen_string_literal: true

# rubocop:disable Layout/LineLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

class Industry < ApplicationRecord
  # Associations
  has_many :committee_industry_mappings, dependent: :destroy
  has_many :committees, through: :committee_industry_mappings

  # Validations
  validates :name, presence: true, uniqueness: true

  # Scopes
  scope :by_sector, ->(sector) { where(sector: sector) }
  scope :with_committee_oversight, -> { joins(:committees).distinct }

  # Instance methods
  def self.classify_stock(ticker_or_company_name)
    # Enhanced classification with ticker mappings and keyword matching
    text = ticker_or_company_name.to_s.upcase
    search_text = ticker_or_company_name.to_s.downcase

    industries = []

    # Direct ticker mappings for common stocks
    industries << find_by(name: 'Technology') if text.match?(/^(AAPL|MSFT|GOOGL|GOOG|META|NVDA|AMD|INTC|CRM|ORCL|IBM|ADBE|CSCO|AVGO|TXN|QCOM|NOW|SNOW|PLTR|CRWD)$/)
    industries << find_by(name: 'Semiconductors') if text.match?(/^(NVDA|AMD|INTC|TSM|ASML|MU|LRCX|AMAT|KLAC|MRVL|ON|TXN|QCOM|AVGO)$/)
    industries << find_by(name: 'Financial Services') if text.match?(/^(V|MA|JPM|BAC|WFC|C|GS|MS|AXP|BLK|SCHW|USB|PNC|TFC|COF|DFS|PYPL|SQ|BTC|ETH|BITB|IBIT)$/)
    industries << find_by(name: 'Healthcare') if text.match?(/^(UNH|JNJ|LLY|ABBV|MRK|PFE|TMO|ABT|DHR|BMY|AMGN|GILD|CVS|CI|HUM|ISRG|SYK|BSX|MDT|VRTX|REGN)$/)
    industries << find_by(name: 'Consumer Goods') if text.match?(/^(PG|KO|PEP|COST|WMT|HD|MCD|NKE|SBUX|TGT|LOW|TJX|DG|DLTR|EL|CL|KMB|GIS|K|CAG)$/)
    industries << find_by(name: 'Energy') if text.match?(/^(XOM|CVX|COP|SLB|EOG|MPC|PSX|VLO|OXY|KMI|WMB|EPD|ET|ENPH|SEDG)$/)
    industries << find_by(name: 'Defense') if text.match?(/^(LMT|RTX|BA|GD|NOC|HII|LHX|TXT|HWM)$/)
    industries << find_by(name: 'Aerospace') if text.match?(/^(BA|RTX|GE|HON|LMT|GD|TXT|SPR)$/)
    industries << find_by(name: 'Telecommunications') if text.match?(/^(T|VZ|TMUS|CMCSA|CHTR|DIS)$/)
    industries << find_by(name: 'Automotive') if text.match?(/^(TSLA|F|GM|TM|HMC|RIVN|LCID|NIO|XPEV|LI)$/)
    industries << find_by(name: 'Real Estate') if text.match?(/^(AMT|PLD|CCI|EQIX|PSA|DLR|O|WELL|SPG|AVB|EQR|VTR|ARE|MAA)$/)

    # Keyword matching for company names
    industries << find_by(name: 'Technology') if search_text.match?(/tech|software|cloud|cyber|data|ai|chip|semi|computing|digital|platform|saas/)
    industries << find_by(name: 'Semiconductors') if search_text.match?(/semiconductor|nvidia|amd|intel/)
    industries << find_by(name: 'Financial Services') if search_text.match?(/bank|financial|invest|insurance|payment|visa|mastercard|bitcoin|crypto|blockchain|capital|securities/)
    industries << find_by(name: 'Healthcare') if search_text.match?(/health|pharma|bio|medic|drug|hospital|clinical|therapeutic/)
    industries << find_by(name: 'Energy') if search_text.match?(/energy|oil|gas|solar|wind|electric|petroleum|renewable/)
    industries << find_by(name: 'Consumer Goods') if search_text.match?(/consumer|retail|product|gamble|food|beverage|brand/)
    industries << find_by(name: 'Defense') if search_text.match?(/defense|weapon|military|missile|lockheed|raytheon|northrop/)
    industries << find_by(name: 'Aerospace') if search_text.match?(/aerospace|aircraft|aviation|boeing|airbus|satellite/)

    # Payroll/HR services
    industries << find_by(name: 'Technology') if text.match?(/^(ADP|PAYX|PAYC|WEX)$/) || search_text.match?(/payroll|workforce|human capital/)

    industries.compact.uniq.presence || [find_by(name: 'Other')]
  end

  def self.classify_employer(employer_name)
    return nil if employer_name.blank?

    text = employer_name.to_s.downcase

    # Healthcare
    if text.match?(/health|pharma|bio|medic|drug|hospital|clinical|therapeutic|kaiser|permanente|unitedhealth|pfizer|johnson.*johnson|merck|abbvie|physician|clinic/)
      return find_by(name: 'Healthcare')
    end

    # Technology
    if text.match?(/tech|software|cloud|cyber|data|ai|chip|semi|computing|digital|platform|saas|google|alphabet|microsoft|apple|meta|facebook|amazon|oracle|salesforce|nvidia|intel|amd|qualcomm|broadcom/)
      return find_by(name: 'Technology')
    end

    # Financial Services
    if text.match?(/bank|financial|invest|insurance|payment|capital|securities|trading|hedge.*fund|jpmorgan|goldman|morgan.*stanley|citigroup|wells.*fargo|citadel|blackrock|vanguard|fidelity|visa|mastercard/)
      return find_by(name: 'Financial Services')
    end

    # Energy
    if text.match?(/energy|oil|gas|solar|wind|electric|petroleum|renewable|exxon|chevron|conocophillips|duke.*energy|nextera/)
      return find_by(name: 'Energy')
    end

    # Defense
    if text.match?(/defense|weapon|military|missile|lockheed|raytheon|northrop|boeing|general.*dynamics/)
      return find_by(name: 'Defense')
    end

    # Aerospace
    if text.match?(/aerospace|aircraft|aviation|boeing|airbus|satellite|space.*exploration/)
      return find_by(name: 'Aerospace')
    end

    # Telecommunications
    if text.match?(/telecom|wireless|broadband|spectrum|at&t|verizon|t-mobile|comcast|charter/)
      return find_by(name: 'Telecommunications')
    end

    # Consumer Goods
    if text.match?(/consumer|retail|brand|procter.*gamble|coca-cola|pepsico|walmart|costco|target|home.*depot|nike|starbucks/)
      return find_by(name: 'Consumer Goods')
    end

    # Automotive
    if text.match?(/auto|car|vehicle|tesla|ford|general.*motors|gm|honda|toyota/)
      return find_by(name: 'Automotive')
    end

    # Real Estate
    if text.match?(/real.*estate|realty|properties|reit|american.*tower|prologis/)
      return find_by(name: 'Real Estate')
    end

    # Semiconductors (subset of Technology)
    if text.match?(/semiconductor|nvidia|intel|amd|qualcomm|broadcom|texas.*instruments|micron/)
      return find_by(name: 'Semiconductors')
    end

    nil
  end
end
# rubocop:enable Layout/LineLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
