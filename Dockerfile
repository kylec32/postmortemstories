FROM ruby:2.1-onbuild as builder

RUN gem install jekyll bundler

WORKDIR /website

COPY . . 

RUN bundle exec jekyll build

FROM nginx:1.13.3-alpine

COPY nginx/default.conf /etc/nginx/conf.d/

RUN rm -rf /usr/share/nginx/html/*

COPY --from=builder /website/_site /usr/share/nginx/html

CMD ["nginx", "-g", "daemon off;"]


