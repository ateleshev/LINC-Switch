%%%===================================================================
%%% @copyright (C) 2012, Erlang Solutions Ltd.
%%% @doc Implementation of sliding window for calculating average
%%% transfer over a period of time
%%% @end
%%%===================================================================

%% Implementation note: sliding window is implemented as a queue
%% using two lists (stacks). It's implementation is simpler,
%% because we always have the same number of entries in the queues.
%%
%% We operate it by modyfying the last added entry (tail), or
%% adding new tail and dropping element from the head (stepping). Once
%% per Len steps we perform an O(N) wrap - switch stacks, which
%% allows us to be amortized O(1) on all operations. Because wrapping
%% is always succeeded by stepping, a nice property holds - tail list
%% is never empty, thus queue's youngest element - hd(Tail) is
%% always available in O(1) time.

-module(sliding_window).

-export([new/2,
         refresh/1,
         bump_transfer/2,
         total_transfer/1,
         length_ms/1]).

-record(bucket, {start :: erlang:timestamp(),
                 transfer = 0 :: integer()}).


%% Properties (hold between steps and bumps):
%% window's tail list is nonempty
%% window's start is equal to oldest element's start
%% window's total_transfer is sum of window's transfers
%% TODO: quickcheck

-record(sliding_window, {size :: integer(),
                         bucket_size_us :: integer(),
                         total_transfer = 0 :: integer(),
                         start :: erlang:timestamp(),
                         head :: [#bucket{}],
                         tail :: [#bucket{}]}).

%% 10^12 and 10^6 for micro-, milli-, mega- manipulation
-define(E12, 1000000000000).
-define(E6, 1000000).

new(BucketCount, BucketSize) when BucketCount > 3, BucketSize > 0 ->
    Now = erlang:now(),
    BucketSizeUs = BucketSize * 1000,
    Buckets = [#bucket{start = now_add(Now, -N * BucketSizeUs)} ||
               N <- lists:seq(0, BucketCount-1)],
    #sliding_window{size = BucketCount,
                    bucket_size_us = BucketSize,
                    total_transfer = 0,
                    head = [],
                    tail = Buckets}.

bump_transfer(Queue0, Transfer) ->
    Queue1 = refresh(Queue0),
    #sliding_window{tail = [TailH | TailT],
                    total_transfer = TotalTransfer} = Queue1,
    NewTailH = TailH#bucket{transfer = TailH#bucket.transfer + Transfer},
    Queue1#sliding_window{tail = [NewTailH | TailT],
                          total_transfer = TotalTransfer + Transfer}.

total_transfer(#sliding_window{total_transfer = TotalTransfer}) ->
    TotalTransfer.

length_ms(#sliding_window{start = Start}) ->
    timer:now_diff(now(), Start) div 1000.

%%--------------------------------------------------------------------
%% Queue helpers
%%--------------------------------------------------------------------

refresh(#sliding_window{tail = [#bucket{start = T} | _],
                               bucket_size_us = BucketSizeUs} = Queue) ->
    case timer:now_diff(now(), T) > BucketSizeUs of
        true ->
            refresh(step(Queue));
        false ->
            Queue
    end.

step(#sliding_window{head = [HeadH | [NewHH|_] = HeadT],
                     tail = OldTail,
                     total_transfer = OldTotalXfer} = Queue) ->
    Queue#sliding_window{head = HeadT,
                         tail = [#bucket{start = now()} | OldTail],
                         start = NewHH#bucket.start,
                         total_transfer = OldTotalXfer - HeadH#bucket.transfer};
step(Queue) -> %% head is too short - wrap
    step(wrap(Queue)).

wrap(#sliding_window{head = Head, tail = Tail} = Queue) ->
    Queue#sliding_window{head = lists:reverse(Tail),
                         tail = lists:reverse(Head)}.

%%--------------------------------------------------------------------
%% Misc. helpers
%%--------------------------------------------------------------------

now_add({MS, S, US}, USDelta) ->
    NewTotal = ?E12 * MS + ?E6 * S + US + USDelta,
    NewMS = NewTotal div ?E12,
    NewSUS = NewTotal rem ?E12,
    NewS = NewSUS div ?E6,
    NewUS = NewSUS rem ?E6,
    {NewMS, NewS, NewUS}.
