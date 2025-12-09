# frozen_string_literal: true

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
end
