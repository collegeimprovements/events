# Example usage of the unified query building approach

# Option 1: Use Events.Repo.Query for everything
query = Events.Repo.Query.new(Product)
        |> Events.Repo.Query.where(status: "active")
        |> Events.Repo.Query.join(:category)
        |> Events.Repo.Query.where({:category, :name, "Electronics"})
        |> Events.Repo.Query.order_by([desc: :price])
        |> Events.Repo.Query.limit(10)

# Execute in different ways:
products = Events.Repo.Query.all(query)
first_product = Events.Repo.Query.first(query)
product_stream = Events.Repo.Query.stream(query)
product_count = Events.Repo.Query.count(query)

# Execute with pagination metadata:
{products, pagination} = Events.Repo.Query.new(Product)
                          |> Events.Repo.Query.where(status: "active")
                          |> Events.Repo.Query.paginate(:offset, limit: 10, offset: 20)
                          |> Events.Repo.Query.paginated_all()

# pagination = %{type: :offset, limit: 10, offset: 20, has_more: true, total_count: nil}

# Option 2: Use CRUD system in build-only mode
crud_query = Events.CRUD.build_token(Product)
             |> Events.CRUD.where(:status, :eq, "active")
             |> Events.CRUD.join(:category)
             |> Events.CRUD.where(:category, :name, :eq, "Electronics")
             |> Events.CRUD.order(:price, :desc)
             |> Events.CRUD.limit(10)
             |> Events.CRUD.execute()  # Returns Ecto.Query, not result

# Then execute as needed:
products = Events.Repo.all(crud_query)
first_product = Events.Repo.one(crud_query)

# Option 3: DSL approach with build-only
import Events.CRUD.DSL

dsl_query = query Product, build_only: true do
  where :status, :eq, "active"
  join :category
  where :category, :name, :eq, "Electronics"
  order :price, :desc
  limit 10
end

# Execute as needed
products = Events.Repo.all(dsl_query)</content>
