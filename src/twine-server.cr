require "./twine/*"

begin
  Twine::Connection.new
rescue e
  abort("Couldn't start Twine server: #{e.message}")
end

if (secret = ENV["TWINE_SECRET"]?).nil?
  secret = "SET SOME SECRET"
  puts "Warning: No secret is set! Set one with $TWINE_SECRET"
end

verbose = !(ENV["TWINE_VERBOSE"]?.nil?)

ENV["PORT"] ||= "4000"
ENV["HOST"] ||= "0.0.0.0"

port = ENV["PORT"].to_i
host = ENV["HOST"].to_s

(Twine::App.new(host: host, port: port, secret: secret, verbose: verbose)).listen
