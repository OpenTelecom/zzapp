-ifndef(ONBILL_HRL).
-include_lib("kazoo/include/kz_types.hrl").
-include_lib("kazoo/include/kz_log.hrl").
-include_lib("kazoo/include/kz_databases.hrl").

-define(APP_NAME, <<"onbill">>).
-define(APP_VERSION, <<"4.0.0">> ).

-define(ONBILL_DB, <<"onbill">>).
-define(ONBILL_GLOBAL_VARIABLES, <<"onbill_global_variables">>).
-define(ONBILL_DOC, <<"onbill">>).
-define(CARRIER_DOC(CarrierName), <<"carrier.", (kz_util:to_binary(CarrierName))/binary>>).
-define(MOD_CONFIG_CRAWLER, <<(?APP_NAME)/binary, ".account_crawler">>).
-define(SYSTEM_CONFIG_DB, <<"system_config">>).
-define(HTML_TO_PDF(TemplateId), <<"php applications/onbill/priv/templates/ru/", (kz_util:to_binary(TemplateId))/binary, ".php">>).
-define(DEFAULT_REGEX, <<"^\\d*$">>).

-define(ONBILL_HRL, 'true').
-endif.
