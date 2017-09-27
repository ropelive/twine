require "yeager"

module Twine
  struct Error
    DATABASE = "DB error occured, check back later."
    INTERNAL = "Internal server error."
    DATA     = "Malformed data received."
    MISSING  = "Missing required data."
    NOTFOUND = "No such data."
  end

  class App < Yeager::App
    PORT = 4000
    HOST = "0.0.0.0"

    WELCOME       = "Welcome to Twine!"
    SERVER_PREFIX = "rope-server-"
    NODE_PREFIX   = "rope-node-"
    KEY_PREFIX    = "twine-"

    private struct KeyGetter
      property prefix

      def initialize(@prefix : String = App::KEY_PREFIX)
      end

      def server(id)
        "#{@prefix}#{SERVER_PREFIX}#{id}"
      end

      def node(id)
        "#{@prefix}#{NODE_PREFIX}#{id}"
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

      # -- Server handlers -- BEGIN

      get "/servers/:id?" do |req, res|
        err, servers, data = get_servers req.params["id"]
        next fail res, err unless err.nil?

        if req.params["id"]?
          if servers.as(Array).size == 1
            res.json data
          else
            fail res, Error::NOTFOUND, 404
          end
        else
          res.json servers
        end
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

        res.status(201).json({"kite_id" => id})
      end

      patch "/servers/:id" do |req, res|
        key = req.params["id"]
        err, servers = get_servers key
        next fail res, err unless err.nil?

        servers = servers.as(Array)
        next fail res, Error::NOTFOUND, 404 if servers.size == 0

        err, data = get_data req
        next fail res, err unless err.nil?

        err = set_data get_key.server(key), data
        next fail res, err unless err.nil?

        success res
      end

      # -- Server handlers -- END

      # -- Node(client) handlers -- BEGIN

      get "/nodes/:id?" do |req, res|
        err, nodes, data = get_nodes req.params["id"]
        next fail res, err unless err.nil?

        if req.params["id"]?
          if nodes.as(Array).size == 1
            res.json data
          else
            fail res, Error::NOTFOUND, 404
          end
        else
          res.json nodes
        end
      end

      delete "/nodes/:id" do |req, res|
        err = delete_node req.params["id"]
        next fail res, err unless err.nil?
        success res
      end

      post "/nodes" do |req, res|
        err, data = get_data req
        next fail res, err unless err.nil?

        err, id = create_node
        next fail res, err unless err.nil?

        res.status(201).json({"kite_id" => id})
      end

      patch "/nodes/:id" do |req, res|
        key = req.params["id"]
        err, nodes = get_nodes key
        next fail res, err unless err.nil?

        nodes = nodes.as(Array)
        next fail res, Error::NOTFOUND, 404 if nodes.size == 0

        err, data = get_data req
        next fail res, err unless err.nil?

        err = set_data get_key.node(key), data
        next fail res, err unless err.nil?

        success res
      end

      # -- Node(client) handlers -- END

    end

    private def fail(res, err, code = 400)
      res.status(code).json({"error" => err})
    end

    private def success(res)
      res.status(200).json({"ok" => true})
    end

    private def get_data(req)
      return nil, JSON.parse_raw(req.body.as(IO).gets_to_end)
    rescue err
      return Error::DATA, nil
    end

    # -- Server helpers -- BEGIN

    def get_servers(id)
      id = "*" if id.nil?

      err, servers = fetch key = get_key.server(id)
      return err, nil, nil unless err.nil?

      if id != "*" && servers.as(Array).size == 1
        err, data = fetch_data key
        return err, servers, data
      end

      return nil, servers, nil
    end

    def delete_server(id)
      delete_multi [get_key.server(id)]
    end

    def create_server
      id = SecureRandom.uuid
      err, added = add get_key.server(id), "version", "1.0"
      return err, added ? id : nil
    end

    # -- Server helpers -- END

    # -- Node(client) helpers -- BEGIN

    def get_nodes(id)
      id = "*" if id.nil?

      err, nodes = fetch key = get_key.node(id)
      return err, nil, nil unless err.nil?

      if id != "*" && nodes.as(Array).size == 1
        err, data = fetch_data key
        return err, nodes, data
      end

      return nil, nodes, nil
    end

    def delete_node(id)
      delete_multi [get_key.node(id)]
    end

    def create_node
      id = SecureRandom.uuid
      err, added = add get_key.node(id), "version", "1.0"
      return err, added ? id : nil
    end

    # -- Node(client) helpers -- END

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

    def fetch_data(key)
      data = redis.hgetall key
      hash = {} of String => String
      data = data.as(Array)
      while data.size > 0
        hash[data.shift.to_s] = data.shift.to_s
      end
      return nil, JSON.parse_raw(hash.to_json)
    rescue Redis::Error
      return Error::DATABASE, nil
    rescue
      return Error::INTERNAL, nil
    end

    def set_data(s_key, data)
      data = data.as(Hash)
      redis.multi do |multi|
        data.each do |key, value|
          multi.hset s_key, key, value
        end
      end
      return nil
    rescue Redis::Error
      return Error::DATABASE
    rescue
      return Error::INTERNAL
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
