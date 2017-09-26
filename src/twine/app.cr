require "yeager"

module Twine
  struct Error
    DATABASE = "DB error occured, check back later."
    INTERNAL = "Internal server error."
    DATA     = "Malformed data received."
    MISSING  = "Missing required data."
  end

  class App < Yeager::App
    PORT    = 4000
    HOST    = "0.0.0.0"
    WELCOME = "Welcome to Twine!"

    SERVER_PREFIX = "rope-server-"

    property url : String = "#{HOST}:#{PORT}"
    private property redis : Redis

    def initialize
      super

      @redis = (Twine::Connection.new).redis

      get "/" do |req, res|
        res.send WELCOME
      end

      get "/servers/:id?" do |req, res|
        err, data = get_servers req.params["id"]
        next fail res, err unless err.nil?

        res.json data
      end

      delete "/servers/:id" do |req, res|
        err = delete_server req.params["id"]
        next fail res, err unless err.nil?
        success res
      end

      post "/servers" do |req, res|
        err, data = get_data req
        next fail res, err unless err.nil?

        err, id = create_server
        next fail res, err unless err.nil?

        res.json({"kite_id" => id})
      end
    end

    private def fail(res, err)
      res.status(500).json({"error" => err})
    end

    private def success(res)
      res.status(200).json({"ok" => true})
    end

    private def get_data(req)
      return nil, JSON.parse_raw(req.body.as(IO).gets_to_end)
    rescue
      return Error::DATA, nil
    end

    def get_servers(id)
      id = "*" if id.nil?
      cursor, keys = redis.scan(0, "#{SERVER_PREFIX}#{id}")
      if keys.is_a?(Array) && cursor != "0"
        until cursor == "0"
          cursor, next_keys = redis.scan(cursor, "#{SERVER_PREFIX}#{id}")
          keys = keys + next_keys if next_keys.is_a?(Array)
        end
      end
      return nil, JSON.parse_raw(keys.to_s)
    rescue Redis::Error
      return Error::DATABASE, nil
    rescue
      return Error::INTERNAL, nil
    end

    def create_server
      id = SecureRandom.uuid
      redis.hset("#{SERVER_PREFIX}#{id}", nil, nil)
      return nil, id
    rescue Redis::Error
      return Error::DATABASE, nil
    rescue
      return Error::MISSING, nil
    end

    def delete_server(id)
      redis.del("#{SERVER_PREFIX}#{id}")
      return nil
    rescue Redis::Error
      return Error::DATABASE
    rescue
      return Error::MISSING
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
