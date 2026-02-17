# CI/CD Pipeline — rare-variant-discovery-pipeline

## GitHub Actions → Docker → AWS ECR

```
Developer Workstation
        │
        │  git commit + push
        ▼
┌─────────────────────────────────────────┐
│              GitHub                     │
│                                         │
│  Branch: main / develop                 │
│  Path filter: dockerfiles/vt/**         │
└───────────────┬─────────────────────────┘
                │
                │  triggers .github/workflows/docker-vt.yml
                ▼
┌─────────────────────────────────────────┐
│         GitHub Actions Runner           │
│                                         │
│  1. checkout repo                       │
│  2. configure AWS credentials           │
│  3. login to AWS ECR                    │
│  4. docker build ./dockerfiles/vt       │
│  5. docker tag                          │
│  6. docker push → AWS ECR              │
└───────────────┬─────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────┐
│              AWS ECR                    │
│                                         │
│  vt-normalize:latest        ← main      │
│  vt-normalize:develop-<sha> ← develop   │
│  vt-normalize:v1.0.0        ← git tag   │
└─────────────────────────────────────────┘
                │
                │  referenced in WDL task runtime{}
                ▼
┌─────────────────────────────────────────┐
│         AWS HealthOmics                 │
│                                         │
│  WDL workflow pulls image from ECR      │
│  runs vt decompose + normalize          │
└─────────────────────────────────────────┘
```

## Trigger Rules

| Event                              | Branch    | Action              |
|------------------------------------|-----------|---------------------|
| push to `dockerfiles/vt/**`        | main      | build + push :latest |
| push to `dockerfiles/vt/**`        | develop   | build + push :develop-\<sha\> |
| git tag `v*.*.*`                   | any       | build + push :v1.0.0 |
| push to `workflows/**/*.wdl`       | any       | validate WDL only   |
