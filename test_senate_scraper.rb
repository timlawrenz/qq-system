require 'net/http'
require 'uri'

url = URI('https://efdsearch.senate.gov/search/home/')
http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true

req = Net::HTTP::Get.new(url)
res = http.request(req)

puts "Status: #{res.code}"

cookies = res.get_fields('set-cookie')&.map { |c| c.split(';').first }&.join('; ')
puts "Cookies: #{cookies}"

csrftoken = res.body.match(/name="csrfmiddlewaretoken" value="([^"]+)"/)
token = csrftoken ? csrftoken[1] : 'Not found'
puts "CSRF Token extracted: #{token}"

if token != 'Not found'
  puts "\nAttempting agreement POST..."
  
  post_url = URI('https://efdsearch.senate.gov/search/home/')
  post_req = Net::HTTP::Post.new(post_url)
  post_req['Cookie'] = cookies
  post_req['Content-Type'] = 'application/x-www-form-urlencoded'
  post_req['Referer'] = 'https://efdsearch.senate.gov/search/home/'
  
  post_req.set_form_data(
    'csrfmiddlewaretoken' => token,
    'prohibition_agreement' => '1'
  )
  
  post_res = http.request(post_req)
  puts "POST Status: #{post_res.code}"
  puts "POST Headers Location: #{post_res['location']}"
  
  new_cookies = post_res.get_fields('set-cookie')&.map { |c| c.split(';').first }&.join('; ')
  puts "New Cookies: #{new_cookies}"
end

