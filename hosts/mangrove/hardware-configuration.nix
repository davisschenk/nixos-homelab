_: {
  boot.initrd.kernelModules = [
    "nvme"
  ];
  boot.initrd.availableKernelModules = [
    "ahci"
    "usb_storage"
    "sd_mod"
    "xhci_pci"
    "usbhid"
    "hid_generic"
  ];
  boot.kernelModules = [ "kvm-intel" ];
}
