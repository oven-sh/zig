Process:

```
git fetch upstream
git diff d03a147ea0a590ca711b3db07106effc559b0fc6 014-dev > ourchanges.patch
git checkout -b upgrade
git reset --hard upstream/master
git apply ourchanges.patch --3way
```

if some parts fail (ie the file was renamed), remove them from the patch and apply them manually

resolve merge conflicts
- Current is the new zig version
- Base is the merge base
- Incoming is our patch

commit
