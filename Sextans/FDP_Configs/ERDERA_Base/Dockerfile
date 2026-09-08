FROM ruby:3.2-bookworm

# Set environment variables for locale
ENV LANG="en_US.UTF-8" LANGUAGE="en_US:UTF-8" LC_ALL="C.UTF-8"

# Update package lists and install dependencies in a single RUN to reduce layers
RUN apt-get update -q && \
    apt-get install -y --no-install-recommends \
    build-essential \
    nano \
    libxml++2.6-dev \
    libraptor2-0 \
    libxslt1-dev \
    locales \
    software-properties-common \
    cron && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Update RubyGems and install Bundler
RUN gem update --system && \
    gem install bundler:2.3.12

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems
COPY Gemfile* ./
RUN bundle install --jobs 4 --retry 3

# Copy script and schemas
COPY do_erdera_configuration.rb .
COPY Schemas/ ./Schemas/

RUN chmod +x do_erdera_configuration.rb

# Run as a non-root, unprivileged user.
RUN useradd -u 1000 -m erdera && chown -R erdera:erdera /app
USER erdera

# Run interactively (needed for port prompt)
ENTRYPOINT ["ruby", "do_erdera_configuration.rb"]
