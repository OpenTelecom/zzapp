-module(onbill_maintenance).

-export([populate_modb_day_with_fee/4
         ,populate_modb_with_fees/3
         ,refresh/0
         ,set_trunkstore_media_handling/0
         ,correct_billing_id/0
         ,set_device_fax_option/0
        ]).

-include("onbill.hrl").

-define(PAUSE, 300).

-spec populate_modb_with_fees(ne_binary(), integer(), integer()) -> ok.
populate_modb_with_fees(AccountId, Year, Month) ->
    kz_bookkeeper_onbill:populate_modb_with_fees(kz_term:to_binary(AccountId), Year, Month).

-spec populate_modb_day_with_fee(ne_binary(), integer(), integer(), integer()) -> ok.
populate_modb_day_with_fee(AccountId, Year, Month, Day) ->
    kz_bookkeeper_onbill:populate_modb_day_with_fee(kz_term:to_binary(AccountId), Year, Month, Day).

-spec refresh() -> 'no_return'.
-spec refresh(ne_binaries(), non_neg_integer()) -> 'no_return'.
-spec refresh(ne_binary(), non_neg_integer(), non_neg_integer()) -> 'ok'.
refresh() ->
    kz_datamgr:revise_docs_from_folder(<<"system_schemas">>, 'onbill', "schemas"),
    Databases = get_databases(),
    refresh(Databases, length(Databases) + 1).

refresh(<<"onbill-", _/binary>> = DbName, DbLeft, Total) ->
    io:format("(~p/~p) refreshing database '~s'~n",[DbLeft, Total, DbName]),
    _ = kz_datamgr:revise_doc_from_file(DbName, 'onbill', <<"views/docs_numbering.json">>),
    timer:sleep(?PAUSE);
refresh(DbName, DbLeft, Total) when is_binary(DbName) ->
    case kz_datamgr:db_classification(DbName) of
        'account' ->
            AccountDb = kz_util:format_account_id(DbName, 'encoded'),
            io:format("(~p/~p) refreshing database '~s'~n",[DbLeft, Total, AccountDb]),
            _ = kz_datamgr:revise_doc_from_file(AccountDb, 'onbill', <<"views/onbill_e911.json">>),
            _ = kz_datamgr:revise_doc_from_file(AccountDb, 'onbill', <<"views/periodic_fees.json">>),
            timer:sleep(?PAUSE);
        'modb' ->
            Modb = kz_util:format_account_modb(DbName, 'encoded'),
            io:format("(~p/~p) refreshing database '~s'~n",[DbLeft, Total, Modb]),
            _ = kz_datamgr:revise_doc_from_file(Modb, 'onbill', <<"views/onbills.json">>),
            timer:sleep(?PAUSE);
        _Else ->
            io:format("(~p/~p) skipping database '~s'~n",[DbLeft, Total, DbName]),
            'ok'
    end.

refresh([], _) -> 'no_return';
refresh([Database|Databases], Total) ->
    _ = refresh(Database, length(Databases) + 1, Total),
    refresh(Databases, Total).

-spec get_databases() -> ne_binaries().
get_databases() ->
        {'ok', Databases} = kz_datamgr:db_info(),
            lists:sort(fun get_database_sort/2, lists:usort(Databases)).

-spec get_database_sort(ne_binary(), ne_binary()) -> boolean().
get_database_sort(Db1, Db2) ->
        kzs_util:db_priority(Db1) < kzs_util:db_priority(Db2).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%  Manipulate trunkstore media handling %%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec set_trunkstore_media_handling() -> 'no_return'.
-spec set_trunkstore_media_handling(ne_binaries(), non_neg_integer()) -> 'no_return'.
set_trunkstore_media_handling() ->
    Databases = get_databases(),
    set_trunkstore_media_handling(Databases, length(Databases) + 1).

set_trunkstore_media_handling([], _) -> 'no_return';
set_trunkstore_media_handling([Database|Databases], Total) ->
    case kz_datamgr:db_classification(Database) of
        'account' ->
            AccountDb = kz_util:format_account_id(Database, 'encoded'),
            case kz_datamgr:get_result_ids(AccountDb, <<"trunkstore/lookup_user_flags">>) of
                {ok,[DocId|_]} ->
                    io:format("(~p/~p) found trunkstore doc in database '~s'~n",[length(Databases) + 1, Total, Database]),
                    {'ok', TsDoc} = kz_datamgr:open_doc(AccountDb, DocId),
                    [Server|H] = kz_json:get_value(<<"servers">>,TsDoc),
                    NewServer = kz_json:set_value([<<"options">>,<<"media_handling">>], <<"process">>, Server),
                    TsDocNew = kz_json:set_value(<<"servers">>, [NewServer|H], TsDoc),
                    kz_datamgr:save_doc(AccountDb,TsDocNew),
                    timer:sleep(?PAUSE);
                _ ->
                    io:format("(~p/~p) no trunkstore doc in database '~s'~n",[length(Databases) + 1, Total, Database]),
                    'ok'
            end;
        _Else ->
            io:format("(~p/~p) skipping database '~s'~n",[length(Databases) + 1, Total, Database]),
            'ok'
    end,
    set_trunkstore_media_handling(Databases, Total).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%u%%%%  Manipulate account billing_id handling %%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec correct_billing_id() -> 'no_return'.
-spec correct_billing_id(ne_binaries(), non_neg_integer()) -> 'no_return'.
correct_billing_id() ->
    Databases = get_databases(),
    correct_billing_id(Databases, length(Databases) + 1).

correct_billing_id([], _) -> 'no_return';
correct_billing_id([Database|Databases], Total) ->
    case kz_datamgr:db_classification(Database) of
        'account' ->
            AccountId = kz_util:format_account_id(Database, 'raw'),
            case kz_services:set_billing_id(AccountId, AccountId) of
                'undefined' ->
                    io:format("(~p/~p) skipping account database '~s' (~p) ~n",[length(Databases) + 1, Total, Database, AccountId]);
                Services ->
                    io:format("(~p/~p) updating account database '~s' (~p) ~n",[length(Databases) + 1, Total, Database, AccountId]),
                    kz_datamgr:save_doc(<<"services">>, kz_services:to_json(Services)),
                    timer:sleep(?PAUSE)
            end;
        _Else ->
            io:format("(~p/~p) skipping database '~s'~n",[length(Databases) + 1, Total, Database]),
            'ok'
    end,
    correct_billing_id(Databases, Total).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%  Manipulate device fax option  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec set_device_fax_option() -> 'no_return'.
-spec set_device_fax_option(ne_binaries(), non_neg_integer()) -> 'no_return'.
set_device_fax_option() ->
    Databases = get_databases(),
    set_device_fax_option(Databases, length(Databases) + 1).

set_device_fax_option([], _) -> 'no_return';
set_device_fax_option([Database|Databases], Total) ->
    case kz_datamgr:db_classification(Database) of
        'account' ->
            AccountDb = kz_util:format_account_id(Database, 'encoded'),
            case kz_datamgr:get_result_ids(AccountDb, <<"devices/crossbar_listing">>) of
                {ok,DocIds} ->
                    device_fax_option(AccountDb, DocIds);
                _ ->
                    io:format("(~p/~p) no trunkstore doc in database '~s'~n",[length(Databases) + 1, Total, Database]),
                    'ok'
            end;
        _Else ->
            io:format("(~p/~p) skipping database '~s'~n",[length(Databases) + 1, Total, Database]),
            'ok'
    end,
    set_device_fax_option(Databases, Total).

device_fax_option(_AccountDb, []) ->
    'ok';
device_fax_option(AccountDb, [DeviceId|T]) ->
    io:format("found device doc ~p in database '~s'~n",[DeviceId, AccountDb]),
    {'ok', Doc} = kz_datamgr:open_doc(AccountDb, DeviceId),
    Keys = [[<<"media">>,<<"fax_option">>]
           ,[<<"media">>,<<"fax">>]
           ,[<<"media">>,<<"peer_to_peer">>]],
    NewDoc = kz_json:delete_keys(Keys, Doc),
    kz_datamgr:save_doc(AccountDb, NewDoc),
    timer:sleep(?PAUSE),
    device_fax_option(AccountDb, T).
