declare module 'phoenix' {
  export class Socket {
    constructor(endPoint: string, opts?: Record<string, unknown>);
    connect(): void;
    disconnect(): void;
    onOpen(callback: () => void): void;
    onClose(callback: () => void): void;
    onError(callback: (error: unknown) => void): void;
    channel(topic: string, params?: Record<string, unknown>): Channel;
  }

  export class Channel {
    join(): Push;
    leave(): Push;
    push(event: string, payload: Record<string, unknown>): Push;
    on<T = unknown>(event: string, callback: (payload: T) => void): number;
    off(event: string, ref?: number): void;
  }

  export class Push {
    receive<T = unknown>(status: string, callback: (response: T) => void): Push;
  }
}
