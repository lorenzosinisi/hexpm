defmodule Mix.Tasks.Hexpm.StatsTest do
  use Hexpm.DataCase

  alias Hexpm.Repository.Download
  alias Hexpm.Store

  setup do
    organization1 = insert(:organization)
    [package1, package2, package3] = insert_list(3, :package)
    package4 = insert(:package, organization_id: organization1.id)
    insert(:release, package: package1, version: "0.0.1")
    insert(:release, package: package1, version: "0.0.2")
    insert(:release, package: package1, version: "0.1.0")
    insert(:release, package: package2, version: "0.0.1")
    insert(:release, package: package2, version: "0.0.2")
    insert(:release, package: package2, version: "0.0.3-rc.1")
    insert(:release, package: package3, version: "0.0.1")
    insert(:release, package: package4, version: "0.0.1")

    %{
      organization1: organization1,
      package1: package1,
      package2: package2,
      package3: package3,
      package4: package4
    }
  end

  test "counts all downloads", %{
    organization1: organization1,
    package1: package1,
    package2: package2,
    package4: package4
  } do
    {bucket, region} =
      case Application.get_env(:hexpm, :logs_buckets) do
        [[bucket, region]] -> {bucket, region}
        _other -> {nil, nil}
      end

    buckets = [[bucket, region]]

    logfile1 =
      read_log(
        "fastly_logs_1.txt",
        repository1: organization1.name,
        package1: package1.name,
        package2: package2.name,
        package4: package4.name
      )
      |> :zlib.gzip()

    logfile2 =
      read_log(
        "fastly_logs_2.txt",
        repository1: organization1.name,
        package1: package1.name,
        package2: package2.name,
        package4: package4.name
      )
      |> :zlib.gzip()

    Store.put(
      region,
      bucket,
      "fastly_hex/2013-11-01T14:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      logfile1,
      []
    )

    Store.put(
      region,
      bucket,
      "fastly_hex/2013-11-01T15:00:00.000-tzletcEGGiI7atIAAAAA.log.gz",
      logfile2,
      []
    )

    Mix.Tasks.Hexpm.Stats.run(~D[2013-11-01], buckets)

    rel1 = Repo.get_by!(assoc(package1, :releases), version: "0.0.1")
    rel2 = Repo.get_by!(assoc(package1, :releases), version: "0.0.2")
    rel3 = Repo.get_by!(assoc(package2, :releases), version: "0.0.2")
    rel4 = Repo.get_by!(assoc(package2, :releases), version: "0.0.3-rc.1")
    rel5 = Repo.get_by!(assoc(package4, :releases), version: "0.0.1")

    downloads = Hexpm.Repo.all(Download)
    assert length(downloads) == 4

    assert Enum.find(downloads, &(&1.release_id == rel1.id)).downloads == 6
    assert Enum.find(downloads, &(&1.release_id == rel2.id)).downloads == 3
    assert Enum.find(downloads, &(&1.release_id == rel3.id)).downloads == 1
    assert Enum.find(downloads, &(&1.release_id == rel5.id)).downloads == 1
    refute Enum.find(downloads, &(&1.release_id == rel4.id))
  end

  defp read_log(path, replaces) do
    Enum.reduce(replaces, read_fixture(path), fn {key, value}, file ->
      String.replace(file, "{#{key}}", value)
    end)
  end
end
