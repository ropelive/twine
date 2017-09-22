require "yeager"

module Twine
  class App < Yeager::App
    PORT    = 4000
    HOST    = "0.0.0.0"
    WELCOME = "Welcome to Twine!"

    property url : String = "#{HOST}:#{PORT}"

    def initialize
      super
      get "/" do |req, res|
        res.send WELCOME
      end
    end

    def listen(block = true)
      spawn do
        begin
          listen PORT, HOST
        rescue e
          puts "Failed to start server!", e
          exit
        end
      end

      Fiber.yield

      if block
        puts "Twine started on #{HOST}:#{PORT}!"
        sleep
      end
    end
  end
end
