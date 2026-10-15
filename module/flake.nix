{
  description = "Logos Tower — vertical jumper for Logos Basecamp";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.3.2";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
