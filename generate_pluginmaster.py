#!/usr/bin/env python3

"""A module for updating the pluginmaster.json file"""

import json
import os
from typing import Any
from time import time
import requests

DOWNLOAD_URL: str = "{}/releases/download/v{}/latest.zip"
GITHUB_RELEASES_API_URL: str = "https://api.github.com/repos/{}/{}/releases/tags/v{}"

DEFAULTS: dict[str, bool | str] = {
    "IsHide": False,
    "IsTestingExclusive": False,
    "ApplicableVersion": "any",
}

DUPLICATES: dict[str, list[str]] = {
    "DownloadLinkInstall": ["DownloadLinkTesting", "DownloadLinkUpdate"],
}

TRIMMED_KEYS: list[str] = [
    "Author",
    "Name",
    "Punchline",
    "Description",
    "Changelog",
    "InternalName",
    "AssemblyVersion",
    "RepoUrl",
    "ApplicableVersion",
    "Tags",
    "CategoryTags",
    "DalamudApiLevel",
    "IconUrl",
    "ImageUrls",
]


def extract_manifests() -> list[dict[str, Any] | Any]:
    """Extracts information from the locally stored manifests.

    Returns:
        list[dict[str, Any] | Any]: A plugin manifest master list.
    """
    manifests: list[dict[str, Any] | Any] = []

    for dirpath, _, filenames in os.walk("./plugins"):
        plugin_name: str = dirpath.split(os.path.sep)[-1]
        if len(filenames) == 0 or f"{plugin_name}.json" not in filenames:
            continue
        with open(f"{dirpath}/{plugin_name}.json", mode="r", encoding="utf-8") as f:
            manifest: dict[str, Any] | Any = json.load(f)
            manifests.append(manifest)

    return manifests


def get_release_download_count(username: str, repo: str, identity: str) -> int:
    """Gets the updated download count for each plugin manifest in the master list.

    Args:
        username (str): The username for owner of the repository.
        repo (str): The name of the repository.
        identity (str): The version of the plugin to base off of.

    Returns:
        int: The total downloads from that plugin repository.
    """
    r = requests.get(
        GITHUB_RELEASES_API_URL.format(username, repo, identity), timeout=10
    )

    if r.status_code == 200:
        data: dict[str, Any] | Any = r.json()
        total: int = 0
        for asset in data["assets"]:
            total += asset["download_count"]
        return total

    return 0


def add_extra_fields(manifests: list[dict[str, Any]]) -> None:
    """Adds extra fields for the given plugin manifest master list.

    Args:
        manifests (list[dict[str, Any]]): The plugin manifest master list.
    """
    for manifest in manifests:
        # generate the download link
        manifest["DownloadLinkInstall"] = DOWNLOAD_URL.format(
            manifest["RepoUrl"], manifest["AssemblyVersion"]
        )
        # add default values if missing
        for k, v in DEFAULTS.items():
            if k not in manifest:
                manifest[k] = v
        # duplicate keys as specified in DUPLICATES
        for source, keys in DUPLICATES.items():
            for k in keys:
                if k not in manifest:
                    manifest[k] = manifest[source]
        manifest["DownloadCount"] = get_release_download_count(
            "thakyZ", manifest["InternalName"], manifest["AssemblyVersion"]
        )


def get_last_updated_times(manifests: list[dict[str, Any]]) -> None:
    """Gets the last updated times for each plugin manifest in the master list.

    Args:
        manifests (list[dict[str, Any]]): The plugin manifest master list.
    """
    with open("pluginmaster.json", mode="r", encoding="utf-8") as f:
        previous_manifests: list[dict[str, Any] | Any] = json.load(f)

        for manifest in manifests:
            manifest["LastUpdate"] = str(int(time()))

            for previous_manifest in previous_manifests:
                if manifest["InternalName"] != previous_manifest["InternalName"]:
                    continue

                if manifest["AssemblyVersion"] == previous_manifest["AssemblyVersion"]:
                    manifest["LastUpdate"] = previous_manifest["LastUpdate"]

                break


def write_master(master: list[dict[str, Any] | Any]) -> None:
    """Writes the given plugin manifest master list to file.

    Args:
        master (list[dict[str, Any] | Any]): The plugin manifest master list.
    """
    # write as pretty json
    with open("pluginmaster.json", mode="w", encoding="utf-8") as f:
        json.dump(master, f, indent=2)


def trim_manifest(plugin: dict[str, Any] | Any) -> dict[str, Any] | Any:
    """Trims unwanted keys from the resulting plugin manifest.

    Args:
        plugin (dict[str, Any] | Any): The plugin manifest to trim the keys of.

    Returns:
        dict[str, Any] | Any: The resulting plugin manifest.
    """
    return {k: plugin[k] for k in TRIMMED_KEYS if k in plugin}


def main():
    """The main entry point for this module."""
    # extract the manifests from the repository
    master = extract_manifests()

    # trim the manifests
    master = [trim_manifest(manifest) for manifest in master]

    # convert the list of manifests into a master list
    add_extra_fields(master)

    # update LastUpdate fields
    get_last_updated_times(master)

    # write the master
    write_master(master)


if __name__ == "__main__":
    main()
