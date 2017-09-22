require "./twine/*"

con = Twine::Connection.new
app = Twine::App.new
app.listen
