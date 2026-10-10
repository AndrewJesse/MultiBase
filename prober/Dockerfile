FROM golang:1.24 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG TARGETARCH
RUN CGO_ENABLED=0 GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /prober .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /prober /prober
ENTRYPOINT ["/prober"]
