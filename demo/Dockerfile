FROM ruby:3.3-slim

WORKDIR /app

COPY nopayn.gemspec Gemfile lib/ lib/
COPY demo/Gemfile demo/Gemfile

RUN cd demo && bundle install --jobs 4

COPY demo/ demo/
COPY lib/ lib/
COPY nopayn.gemspec Gemfile ./

EXPOSE 3000

WORKDIR /app/demo
CMD ["ruby", "app.rb"]
