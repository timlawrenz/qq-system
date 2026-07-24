require 'net/http'
require 'uri'
require 'json'

# Step 1: Get the CSRF token and initial cookies
url = URI('https://efdsearch.senate.gov/search/home/')
http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true

req = Net::HTTP::Get.new(url)
res = http.request(req)

cookies = res.get_fields('set-cookie')&.map { |c| c.split(';').first }
cookies_hash = cookies.to_h { |c| c.split('=', 2) }
csrftoken = res.body.match(/name="csrfmiddlewaretoken" value="([^"]+)"/)[1]

# Step 2: Post the agreement form to get the sessionid
post_url = URI('https://efdsearch.senate.gov/search/home/')
post_req = Net::HTTP::Post.new(post_url)
post_req['Cookie'] = cookies.join('; ')
post_req['Content-Type'] = 'application/x-www-form-urlencoded'
post_req['Referer'] = 'https://efdsearch.senate.gov/search/home/'

post_req.set_form_data(
  'csrfmiddlewaretoken' => csrftoken,
  'prohibition_agreement' => '1'
)

post_res = http.request(post_req)
new_cookies = post_res.get_fields('set-cookie')&.map { |c| c.split(';').first }
new_cookies_hash = new_cookies.to_h { |c| c.split('=', 2) }

# Combine cookies
final_cookies = cookies_hash.merge(new_cookies_hash).map { |k, v| "#{k}=#{v}" }.join('; ')

puts "Acquired sessionid. Attempting API fetch..."

# Step 3: Hit the DataTables API endpoint
# This is the endpoint the front-end hits when you submit the search form
api_url = URI('https://efdsearch.senate.gov/search/report/data/')
api_req = Net::HTTP::Post.new(api_url)

api_req['Cookie'] = final_cookies
api_req['Content-Type'] = 'application/x-www-form-urlencoded'
api_req['Referer'] = 'https://efdsearch.senate.gov/search/'
api_req['X-CSRFToken'] = cookies_hash['csrftoken']

# Example payload asking for PTRs (Periodic Transaction Reports)
api_req.set_form_data(
  'start' => '0',
  'length' => '10', # Get first 10
  'report_types' => '[11]', # PTRs (Periodic Transaction Reports)
  'filer_types' => '[]',
  'submitted_start_date' => '01/01/2026 00:00:00',
  'submitted_end_date' => '',
  'candidate_state' => '',
  'senator_state' => '',
  'office_id' => '',
  'first_name' => '',
  'last_name' => ''
)

api_res = http.request(api_req)

puts "API Status: #{api_res.code}"
puts "Response Body Preview: #{api_res.body[0..300]}..."

if api_res.code == '200'
  data = JSON.parse(api_res.body)
  puts "Records found: #{data['recordsTotal']}"
end
