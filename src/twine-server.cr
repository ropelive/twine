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

(Twine::App.new(secret: secret)).listen
