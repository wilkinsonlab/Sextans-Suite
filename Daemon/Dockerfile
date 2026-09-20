#FROM ruby:3.0.6
FROM ruby:3.4.10-alpine
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache build-base git make gcc libffi-dev ruby-dev zlib-dev yaml-dev curl

RUN gem install bundler
# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1
RUN mkdir -p /app
COPY . /app
WORKDIR /app

RUN bundle install

# Bundler installs its own newer `resolv` (pinned in the Gemfile above) and the
# app uses that one at runtime, but Ruby's bundled *default* gemspec for the
# older vulnerable version is still physically present on disk and unused --
# Trivy's gemspec scanner flags it regardless of which copy actually loads.
# Confirmed dead weight (an older Alpine-packaged default copy too); remove.
RUN rm -rf /usr/local/lib/ruby/gems/3.4.0/specifications/default/resolv-0.7.1.gemspec \
    /usr/local/lib/ruby/gems/3.4.0/gems/resolv-0.7.1 \
    /usr/lib/ruby/gems/3.4.0/specifications/default/resolv-0.6.2.gemspec \
    /usr/lib/ruby/gems/3.4.0/gems/resolv-0.6.2

# RUN git clone https://github.com/ejp-rd-vp/CARE-SM-Implementation.git
# CARE-SM-Implementation (v1) is superseded by CARE-Semantic-Model-Version-2, which
# consolidates the YARRRML mapping, RDF examples, and Toolkit into one actively-edited repo.
RUN git clone https://github.com/wilkinsonlab/CARE-Semantic-Model-Version-2.git

# Run as a non-root, unprivileged user. The install script opens up the
# bind-mounted ./data directory (chmod o+rwX) since this fixed UID won't
# generally match the host user's UID.
RUN addgroup -g 1000 cdeb && adduser -D -u 1000 -G cdeb cdeb && \
    chown -R cdeb:cdeb /app
USER cdeb

ENTRYPOINT ["sh", "entrypoint-cdev2.sh"]
