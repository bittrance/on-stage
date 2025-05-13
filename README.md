# Short-lived environments GitHub Action

```
docker build -t bittrance/shortlived-environment .
```

```shell
docker run --rm \
  -e GH_TOKEN=$(gh auth token) \
  -e SELECT_LABEL=integrate-me \
  -e REPO_SLUG=bittrance/shortlived-environment-e2e \
  -v .:/workspace \
  bittrance/shortlived-environment:latest
```
