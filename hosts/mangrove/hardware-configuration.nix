_: {
  boot.initrd.kernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "hid_generic"
  ];
  boot.initrd.availableKernelModules = [
    "ahci"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];
}
