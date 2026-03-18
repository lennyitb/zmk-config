KEYMAP = config/corne.keymap
WYSIWYG = config/wysiwyg/corne.keymap
TRANSLATE = ruby translate.rb
REPO := $(shell gh repo view --json nameWithOwner --jq '.nameWithOwner')

.PHONY: get-firmware wysiwyg ansi

get-firmware:
	$(eval RUN_ID := $(shell gh run list --repo $(REPO) --limit 1 --status completed --json databaseId --jq '.[0].databaseId'))
	@rm -rf firmware
	gh run download $(RUN_ID) --repo $(REPO) --dir firmware
	@echo "Firmware downloaded to firmware/"
	@ls firmware/firmware/

wysiwyg:
	$(TRANSLATE) --to-wysiwyg $(KEYMAP) -o $(WYSIWYG)

ansi:
	$(TRANSLATE) --to-ansi $(WYSIWYG) -o $(KEYMAP)
