.PHONY: all packs clean preview install test

# Generate all bundled sound packs from scratch
packs:
	python3 src/generate-placeholders.py

# Generate and preview all sounds (plays through system audio)
preview:
	python3 src/generate-placeholders.py --preview

# Generate a single pack
pack-%:
	python3 src/generate-placeholders.py --pack $*

# Run local install (from cloned repo)
install:
	bash install.sh

# Run uninstall
uninstall:
	bash uninstall.sh

# Open admin menu
admin:
	bash ~/.hermes/awooga-sfx/src/admin.sh

# Test a specific sound
test-%:
	AWOOGA_DIR="$(shell pwd)/packs" bash src/play-sound.sh $*

# Clean generated packs (keeps source)
clean:
	find packs -name '*.wav' -delete
	find packs -name 'pack.yaml' -delete

# Validate all pack.yaml files
validate:
	@for dir in packs/*/; do \
		echo "Checking $$dir/pack.yaml..."; \
		grep -q 'name:' "$$dir/pack.yaml" && \
		grep -q 'events:' "$$dir/pack.yaml" && \
		echo "  ✅ OK" || echo "  ❌ MISSING FIELDS"; \
	done