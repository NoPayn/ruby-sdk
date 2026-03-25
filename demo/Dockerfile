FROM ruby:3.3-slim

WORKDIR /app

COPY nopayn.gemspec Gemfile ./
COPY lib/ lib/
COPY demo/Gemfile demo/Gemfile

RUN cd demo && bundle install --jobs 4

COPY demo/ demo/

EXPOSE 3000

WORKDIR /app/demo
CMD ["ruby", "app.rb"]
