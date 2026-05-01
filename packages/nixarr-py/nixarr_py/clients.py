"""
Pre-configured API clients for Nixarr-managed services.
"""

import prowlarr
import radarr
import sonarr

from nixarr_py.config import get_simple_service_config as _get_simple_service_config


def _make_arr_client(service: str, module):
    cfg = _get_simple_service_config(service)

    with open(cfg.api_key_file, "r", encoding="utf-8") as file_handle:
        api_key = file_handle.read().strip()

    configuration = module.Configuration(
        host=cfg.base_url,
        api_key={"X-Api-Key": api_key},
    )

    return module.ApiClient(configuration)


def prowlarr_client() -> prowlarr.ApiClient:
    return _make_arr_client("prowlarr", prowlarr)


def radarr_client() -> radarr.ApiClient:
    return _make_arr_client("radarr", radarr)


def sonarr_client() -> sonarr.ApiClient:
    return _make_arr_client("sonarr", sonarr)