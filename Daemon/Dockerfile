# ---- builder: compile the native gems with the full toolchain, kept OUT of the runtime image ----
# The toolchain (build-base/gcc + the -dev packages) also drags in Alpine's own `ruby`/`ruby-libs`/
# `ruby-dev`/`ruby-rdoc` packages (ruby-dev's dependencies) -- a second Ruby, used only for build
# headers, that accounted for ~half of this image's Trivy findings when it shipped in the runtime
# layer. A multi-stage build leaves all of that here and copies only the compiled gems forward.
FROM ruby:3.4.10-alpine AS builder
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache build-base git make gcc libffi-dev ruby-dev zlib-dev yaml-dev
RUN gem install bundler
# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
# CARE-SM-Implementation (v1) is superseded by CARE-Semantic-Model-Version-2, which consolidates the
# YARRRML mapping, RDF examples, and Toolkit into one actively-edited repo. Cloned here and pulled
# fresh at runtime by the daemon (see transform-cdev2.rb).
RUN git clone https://github.com/wilkinsonlab/CARE-Semantic-Model-Version-2.git

# ---- runtime: official ruby + only what the app actually needs at run time --------------------
FROM ruby:3.4.10-alpine
# Runtime shared libraries the compiled gems load (determined with ldd against the built bundle:
# libgcc/gmp/yaml/zlib; libffi kept defensively), plus git + curl the daemon itself uses at run time
# (it git-pulls the CARE-SM-2 mapping and speaks HTTP to Virtuoso). No build toolchain, no -dev
# packages, no second (Alpine) Ruby, no rdoc docs -- those stay in the builder stage.
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache git curl libffi gmp yaml zlib libgcc
# Remove the compromised emSign ECC Root CA - G3 from the OS trust bundle (the fixed Alpine
# ca-certificates-bundle that drops it isn't in this release's repo yet). See the script header.
COPY strip-compromised-ca.sh /usr/local/bin/strip-compromised-ca.sh
RUN sh /usr/local/bin/strip-compromised-ca.sh
RUN bundle config --global frozen 1
WORKDIR /app
# Compiled gems and the pre-cloned mapping repo, straight from the builder stage.
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app/CARE-Semantic-Model-Version-2 /app/CARE-Semantic-Model-Version-2
COPY . /app

# Bundler installs its own newer `resolv` (pinned in the Gemfile) and the app loads that one, but
# Ruby's bundled *default* gemspec for the older vulnerable version is still physically present and
# unused -- Trivy's gemspec scanner flags it regardless of which copy actually loads. Remove it.
RUN rm -rf /usr/local/lib/ruby/gems/3.4.0/specifications/default/resolv-0.7.1.gemspec \
    /usr/local/lib/ruby/gems/3.4.0/gems/resolv-0.7.1

# Run as a non-root, unprivileged user. The install script opens up the bind-mounted ./data
# directory (chmod o+rwX) since this fixed UID won't generally match the host user's UID.
RUN addgroup -g 1000 cdeb && adduser -D -u 1000 -G cdeb cdeb && \
    chown -R cdeb:cdeb /app
USER cdeb

ENTRYPOINT ["sh", "entrypoint-cdev2.sh"]
