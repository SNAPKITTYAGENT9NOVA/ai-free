# Stage 1 — Run Instructions

## Build container
```sh
docker build -t tablekeeper-stage-1 .
```

## Run container
```sh
docker run -d -p 8080:8080 -e PORT=8080 tablekeeper-stage-1
```
