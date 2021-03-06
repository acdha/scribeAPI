FROM zooniverse/ruby:2.1.5

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y git nodejs npm coffeescript && \
    ln -s /usr/bin/nodejs /usr/local/bin/node

ADD . /src/

WORKDIR /src/

RUN bundle install

RUN npm install

EXPOSE 80

ENTRYPOINT ["rails", "server", "-p", "80"]
