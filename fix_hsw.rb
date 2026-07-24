require 'net/http'
require 'json'

def download_data
  # The house / senate data has been IP-blocked on AWS or the bucket removed.
  # the old quiverquant data is no longer accessible via S3.
  # For now, Quiver api returns 500 when accessing /congresstrading
end
