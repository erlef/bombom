# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 Stritzinger GmbH

{ pkgs, lib, config, inputs, ... }:

let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.system;
    config.allowUnfree = true;
  };
in
{
  packages = with pkgs; [
    git
    reuse
  ];

  languages.erlang = {
    enable = true;
    # Switch back to normal packages when Erlang 28.2 is available there
    package = pkgs-unstable.beam28Packages.erlang;
  };
}
