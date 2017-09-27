require "./twine/*"

begin
  Twine::Connection.new
rescue e
  abort("Couldn't start Twine server: #{e.message}")
end

(Twine::App.new).listen
