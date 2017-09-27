require "yeager"

module Twine
  struct Error
    DATABASE = "DB error occured, check back later."
    INTERNAL = "Internal server error."
    DATA     = "Malformed data received."
    MISSING  = "Missing required data."
  end

  class App < Yeager::App
    PORT = 4000
    HOST = "0.0.0.0"

    WELCOME       = "Welcome to Twine!"
    SERVER_PREFIX = "rope-server-"
    KEY_PREFIX    = "twine-"

    private struct KeyGetter
      property prefix

      def initialize(@prefix : String = App::KEY_PREFIX)
      end

      def server(id)
        "#{@prefix}#{SERVER_PREFIX}#{id}"
      end

      def any
        "#{@prefix}*"
      end
    end

    property url : String
    getter get_key : KeyGetter

    private getter redis : Redis
    private getter server : HTTP::Server

    def initialize(@host = HOST, @port = PORT, @prefix = KEY_PREFIX)
      super()

      @redis = (Twine::Connection.new).redis

      @url = "#{@host}:#{@port}"
      @server = HTTP::Server.new(@host, @port, [@handler])
      @get_key = KeyGetter.new @prefix

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
    rescue err
      return Error::DATA, nil
    end

    def get_servers(id)
      id = "*" if id.nil?
      fetch get_key.server(id)
    end

    def delete_server(id)
      delete_multi [get_key.server(id)]
    end

    def create_server
      id = SecureRandom.uuid
      err, added = add get_key.server(id)
      return err, added ? id : nil
    end

    def get_all
      fetch get_key.any
    end

    def delete_all
      err, all_keys = get_all
      return err unless err.nil?
      delete_multi all_keys if all_keys.is_a?(Array)
    end

    def add(key, prop = nil, value = nil)
      redis.hset(key, prop, value)
      return nil, true
    rescue Redis::Error
      return Error::DATABASE, nil
    rescue
      return Error::MISSING, nil
    end

    def fetch(key)
      cursor, keys = redis.scan(0, key)
      if keys.is_a?(Array) && cursor != "0"
        until cursor == "0"
          cursor, next_keys = redis.scan(cursor, key)
          keys = keys + next_keys if next_keys.is_a?(Array)
        end
      end
      return nil, JSON.parse_raw(keys.to_s)
    rescue Redis::Error
      return Error::DATABASE, nil
    rescue
      return Error::INTERNAL, nil
    end

    def delete_multi(keys)
      redis.multi do |multi|
        keys.each do |key|
          multi.del key
        end
      end
      return nil
    rescue Redis::Error
      return Error::DATABASE
    rescue
      return Error::INTERNAL
    end

    def listen(block = true)
      @server = HTTP::Server.new(@host, @port, [@handler])
      {% if !flag?(:without_openssl) %}
      @server.tls = nil
      {% end %}

      spawn do
        begin
          @server.listen
        rescue e
          puts "Failed to start server!", e
          exit
        end
      end

      Fiber.yield

      if block
        puts "Twine started on #{@host}:#{@port}!"
        sleep
      end
    end

    def close
      @server.close
    end
  end
end
