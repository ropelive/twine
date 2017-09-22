# Twine

Twine is the registry and router for multiple Rope servers.
It's basically a web server with routing capabilities and a registry
endpoint for kites connected to Rope servers via Redis.

[![Build Status](https://img.shields.io/travis/koding/twine/master.svg)](https://travis-ci.org/koding/twine)

## Installation

    $ crystal deps install
    $ crystal build src/twine-server.cr --release

## Usage

    $ ./twine-server                  # will start twine server on 0.0.0.0:4000

## Development

    $ crystal spec -v                 # to run specs after making changes
    $ crystal run src/twine-server.cr # to build and start with latest changes

## Contributing

1. Fork it ( https://github.com/koding/twine/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [gokmen](https://github.com/gokmen) Gokmen Goksel - creator, maintainer
