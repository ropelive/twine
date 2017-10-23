FROM crystallang/crystal:0.23.1

WORKDIR /app

ADD . .

RUN crystal deps install

# see https://github.com/crystal-lang/crystal/issues/4719 for --no-debug
# ENV LLVM_ENABLE_ASSERTIONS=OFF 
RUN crystal build src/twine-server.cr --release --no-debug