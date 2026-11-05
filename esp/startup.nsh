@echo -off
echo tapas SD test: looking for the ESP
for %a in 0 1 2 3 4 5 6 7 8 9
  if exist fs%a:\tapas-esp.txt then
    echo SD ESP found: fs%a
    echo ok >a fs%a:\done.txt
    map >a fs%a:\map.txt
    devtree >a fs%a:\devtree.txt
    drivers >a fs%a:\drivers.txt
    dh -p BlockIo >a fs%a:\blockio.txt
    echo logs written
    if exist fs%a:\EFI\Microsoft\Boot\bootmgfw.efi then
      echo starting Windows Boot Manager in 3 s
      stall 3000000
      fs%a:\EFI\Microsoft\Boot\bootmgfw.efi
    endif
  endif
endfor
