@echo -off
echo tapas SD test: looking for the ESP
for %a in 0 1 2 3 4 5 6 7 8 9
  if exist fs%a:\tapas-esp.txt then
    echo SD ESP found: fs%a (no log files: SD writes fail in UEFI)
    map
    if exist fs%a:\EFI\Microsoft\Boot\bootmgfw.efi then
      echo starting Windows Boot Manager in 5 s
      stall 5000000
      fs%a:\EFI\Microsoft\Boot\bootmgfw.efi
      echo bootmgfw returned
    else
      echo bootmgfw.efi NOT found on fs%a
    endif
  endif
endfor
