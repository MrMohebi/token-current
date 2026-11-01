FROM golang:1-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /relay ./cmd/token-current-relay
FROM alpine:3
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 current && mkdir /data && chown current:current /data
COPY --from=build /relay /token-current-relay
USER current
EXPOSE 8787
VOLUME /data
ENTRYPOINT ["/token-current-relay"]
CMD ["serve", "--listen", "0.0.0.0:8787", "--state", "/data/relay.json"]
