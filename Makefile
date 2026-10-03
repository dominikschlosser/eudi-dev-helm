CHART := charts/eudi-dev

.PHONY: deps lint readme test

deps:
	helm dependency build $(CHART)

lint: deps
	helm lint $(CHART)
	ct lint --config ct.yaml --all --check-version-increment=false

# Regenerates the parameter tables in the chart README from values.yaml.
readme:
	npx -y @bitnami/readme-generator-for-helm@2 -v $(CHART)/values.yaml -r $(CHART)/README.md

# Creates a kind cluster, installs the chart in every test setup and checks the wallet.
test:
	test/e2e.sh --kind
