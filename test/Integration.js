// spawn uses detached=true so the POSIX process group includes build descendants.
export const terminateAndWaitImpl = process => completed => done => () => {
  if (completed()) return done();
  process.once("close", () => done());
  try {
    globalThis.process.kill(-process.pid, "SIGKILL");
  } catch (error) {
    if (error.code !== "ESRCH") throw error;
  }
};
