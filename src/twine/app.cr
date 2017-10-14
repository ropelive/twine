require "yeager"

module Twine
  struct Error
    DATABASE     = "DB error occured, check back later."
    INTERNAL     = "Internal server error."
    DATA         = "Malformed data received."
    MISSING      = "Missing required data."
    NOTFOUND     = "No such data."
    UNAUTHORIZED = "Authorization failure."
    NOTAVAILABLE = "No server available to connect."
  end

  class App < Yeager::App
    PORT = 4000
    HOST = "0.0.0.0"

    SERVER_MAX = 100

    WELCOME       = "Welcome to Twine!"
    SERVER_PREFIX = "rope-server-"
    NODE_PREFIX   = "rope-node-"
    KEY_PREFIX    = "twine-"

    private struct KeyGetter
      property prefix

      def initialize(@prefix : String = App::KEY_PREFIX)
      end

      def server(id = "")
        "#{@prefix}#{SERVER_PREFIX}#{id}"
      end

      def node(id = "")
        "#{@prefix}#{NODE_PREFIX}#{id}"
      end

      def custom(name)
        "#{@prefix}#{name}"
      end

      def any
        "#{@prefix}*"
      end
    end

    getter url : String
    getter key_for : KeyGetter

    private getter redis : Redis
    private getter server : HTTP::Server

    private property secret : String

    def initialize(@host = HOST,
                   @port = PORT,
                   @prefix = KEY_PREFIX,
                   @verbose = false,
                   @secret = SecureRandom.uuid)
      super()

      @redis = (Twine::Connection.new).redis

      @url = "#{@host}:#{@port}"
      @server = HTTP::Server.new(@host, @port, [@handler])
      @key_for = KeyGetter.new @prefix

      get "/" do |req, res|
        res.send WELCOME
      end

      get "/connect" do |req, res|
        err, servers, data = get_available_server
        if !err.nil? || servers.as(Array).size == 0
          next fail res, Error::NOTAVAILABLE
        end

        server_id = servers.as(Array)[0]
        data = data.as(Hash)

        if url = data["url"]?
          res.redirect url.to_s
        else
          res.redirect "//#{@url}/connect/#{server_id}"
        end
      end

      # -- Authorization check over Bearer token in Header

      all "/*" do |req, res, continue|
        bearer = req.headers["Bearer"]?
        if !bearer.nil? && check_secret bearer
          continue.call
        else
          fail res, Error::UNAUTHORIZED, 401
        end
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

        err, id = create_server data
        next fail res, err unless err.nil?

        res.status(201).json({"id" => id})
      end

      patch "/servers/:id" do |req, res|
        key = req.params["id"]
        err, servers = get_servers key
        next fail res, err unless err.nil?

        servers = servers.as(Array)
        next fail res, Error::NOTFOUND, 404 if servers.size == 0

        err, data = get_data req
        next fail res, err unless err.nil?

        err = set_data key_for.server(key), data
        next fail res, err unless err.nil?

        if data.as(Hash)["connections"]?
          err = sort_servers
          next fail res, err unless err.nil?
        end

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

        res.status(201).json({"id" => id})
      end

      patch "/nodes/:id" do |req, res|
        key = req.params["id"]
        err, nodes = get_nodes key
        next fail res, err unless err.nil?

        nodes = nodes.as(Array)
        next fail res, Error::NOTFOUND, 404 if nodes.size == 0

        err, data = get_data req
        next fail res, err unless err.nil?

        err = set_data key_for.node(key), data
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

      err, servers = fetch key = key_for.server(id)
      return err, nil, nil unless err.nil?

      servers.as(Array).map! &.as(String).lchop key_for.server

      if id != "*" && servers.as(Array).size == 1
        err, data = fetch_data key

        data = data.as(Hash)
        data["id"] = key.lchop key_for.server

        return err, servers, data
      end

      return nil, servers, nil
    end

    def delete_server(id)
      err = delete_multi [key_for.server(id)]
      return err unless err.nil?

      sort_servers id
    end

    def create_server(data = nil)
      id = SecureRandom.uuid

      data = data.as(Hash)
      data["version"] = "1.0" unless data["version"]?
      data["connections"] = "0" unless data["connections"]?

      err = set_data key_for.server(id), data
      return err, nil unless err.nil?

      err = sort_servers id
      return err, err.nil? ? id : nil
    end

    def sort_servers(id = nil)
      servers_list = key_for.custom("servers")
      by = "#{key_for.server("*")}->connections"
      sort_list servers_list, by, id
    end

    def get_available_server
      servers_list = key_for.custom("servers")
      get_servers redis.lrange(servers_list, 0, 0)[0]?
    end

    # -- Server helpers -- END

    # -- Node(client) helpers -- BEGIN

    def get_nodes(id)
      id = "*" if id.nil?

      err, nodes = fetch key = key_for.node(id)
      return err, nil, nil unless err.nil?

      if id != "*" && nodes.as(Array).size == 1
        err, data = fetch_data key

        data = data.as(Hash)
        data["id"] = key.lchop key_for.node

        return err, nodes, data
      end

      nodes.as(Array).map! &.as(String).lchop key_for.node

      return nil, nodes, nil
    end

    def delete_node(id)
      delete_multi [key_for.node(id)]
    end

    def create_node
      id = SecureRandom.uuid
      err = set_data key_for.node(id), {
        "version" => "1.0",
      }
      return err, err.nil? ? id : nil
    end

    # -- Node(client) helpers -- END

    # -- Redis helpers -- BEGIN

    def get_all
      fetch key_for.any
    end

    def delete_all
      err, all_keys = get_all
      return err unless err.nil?
      delete_multi all_keys if all_keys.is_a?(Array)
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

    def sort_list(list, by, id = nil)
      redis.rpush(list, id) unless id.nil?
      redis.sort(list, by: by, store: list)
      return nil
    rescue Redis::Error
      return Error::DATABASE
    rescue
      return Error::INTERNAL
    end

    # -- Redis helpers -- END

    # -- App helpers -- BEGIN

    def check_secret(secret) : Bool
      @secret == secret
    end

    def listen(block = true)
      handlers = [] of Yeager::HTTPHandler | HTTP::LogHandler
      handlers << HTTP::LogHandler.new if @verbose
      handlers << @handler

      @server = HTTP::Server.new(@host, @port, handlers)

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

    # -- App helpers -- END

  end
end
