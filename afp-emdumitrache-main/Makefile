.SILENT:

.PHONY: grammar install test clean

default: build

FILE ?= ""

RUN_ARGS =
ifneq (${FILE}, "")
	RUN_ARGS = exes -- ${FILE}
endif

run:
	cabal run ${RUN_ARGS}

grammar:
	cabal install BNFC --overwrite-policy=always
	bnfc -d grammar/Lang.cf -o grammar >> /dev/null

build: grammar
	cabal build

install: grammar
	cabal install --overwrite-policy=always

test: grammar
	cabal test

clean:
	rm -rf grammar/Lang
	cabal clean
