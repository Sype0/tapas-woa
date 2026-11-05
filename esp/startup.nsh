@echo -off
echo tapas SD test: looking for the ESP
for %a in 0 1 2 3 4 5 6 7 8 9
  if exist fs%a:\tapas-esp.txt then
    fs%a:
    map -r >a map.txt
    devtree >a devtree.txt
    drivers >a drivers.txt
    dh -p BlockIo >a blockio.txt
    echo ok >a done.txt
    echo SD ESP ok: fs%a - logs written
    if exist fs%a:\EFI\Microsoft\Boot\bootmgfw.efi then
      echo starting Windows Boot Manager in 3 s
      stall 3000000
      fs%a:\EFI\Microsoft\Boot\bootmgfw.efi
    endif
  endif
endfor
