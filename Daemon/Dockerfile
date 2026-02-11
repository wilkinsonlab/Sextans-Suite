#FROM ruby:3.0.6
FROM ruby:3.3.6-alpine3.21
RUN apk update && apk add --no-cache build-base git make gcc libffi-dev ruby-dev zlib-dev

# RUN apt-get -y update
# RUN apt-get -y dist-upgrade
# RUN apt-get -y update
# RUN apt-get -y install git
RUN gem install bundler
# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1
RUN mkdir -p /app
COPY . /app
WORKDIR /app

RUN bundle install

# RUN git clone https://github.com/ejp-rd-vp/CARE-SM-Implementation.git 
RUN git clone https://github.com/CARE-SM/CARE-SM-Implementation.git

ENTRYPOINT ["sh", "entrypoint-cdev2.sh"]
