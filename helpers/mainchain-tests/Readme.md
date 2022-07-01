This folder contains tests when the mainchain state is forked. As foundry cannot do this alone, you'd need to fork mainchain with ganache and then fork from ganache:

```
ganache --fork -p 7545

forge test -f http://localhost:7545 --match-test testClaimTokensNewMapperMainchain -vvv
```