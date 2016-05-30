FROM crystallang/crystal:0.17.4

# Install git
RUN apt-get update && apt-get -y install git libyaml-0-2 postgresql-client curl && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install crystal deps
ADD shard.yml /app/
ADD shard.lock /app/
WORKDIR /app
RUN crystal deps

# Add and build bot and web
ADD . /app
RUN crystal build src/mvam-bot.cr --release
RUN crystal build src/mvam-web.cr --release

# Start the bot
CMD "./mvam-bot"
