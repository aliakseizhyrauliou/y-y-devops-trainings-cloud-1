FROM golang:1.21 AS build

WORKDIR /app

COPY . .

RUN go mod download

RUN CGO_ENABLED=0 go build -o catgpt

FROM gcr.io/distroless/static-debian12:latest-amd64

COPY --from=build /app/catgpt .

EXPOSE 8080 9090

CMD ["./catgpt"]