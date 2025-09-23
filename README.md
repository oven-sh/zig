Bun's fork of zig

Upgrade info:

Process:

```
git fetch upstream
git fetch upstream --tags
git checkout -b UPGRADE_BRANCH_NAME
git reset --soft $(git merge-base 0.15.1 014-dev)
git commit -m "patches"
git config --global merge.conflictstyle zdiff3
git rebase upstream/master # alternatively, the changes can be made into a patch file and manually applied
```

if some parts fail (ie the file was renamed), remove them from the patch and apply them manually

resolve merge conflicts
- Current is the new zig version
- Base is the merge base
- Incoming is our patch

commit

Building a Release build locally:
```
mkdir build
cd build
cmake .. -DZIG_STATIC_LLVM=ON -DZIG_STATIC_ZSTD=ON -DCMAKE_PREFIX_PATH="$(brew --prefix llvm@20);$(brew --prefix lld);$(brew --prefix zstd)" -DCMAKE_BUILD_TYPE=Release -GNinja -DZIG_NO_LIB=ON
ninja install
```

Building zig only given stage3
```
stage3/bin/zig build -p stage4 -Denable-llvm -Dno-lib
```

Updating CI:
- If there was an llvm upgrade, need to upgrade zig-bootstrap ref and check that the sed commands will still work
- Update zls
- zls will silently be missing if the build fails in CI so test the build locally